# Health v1.0 — Fase 5A — Auditoria de confronto e contrato canônico (Nutrição)

| Campo | Valor |
|-------|-------|
| Status | **ENCERRADA E DOCUMENTADA** (contrato 5B D1–D42 reconciliado) |
| Data | 2026-07-18 |
| Branch | `feature/health-v1-foundation` |
| HEAD | `c8893ed0497623956ab1390da4c020d137268854` |
| Tracking | `origin/feature/health-v1-foundation` |
| Divergência | `0/0` |
| Working tree | somente este relatório (untracked) |
| Escopo | Auditoria + contrato alvo. **Zero** implementação, Rules, Functions, deploy, commit, push. |

```text
FASE 4E — Agenda Preventiva: ENCERRADA
FASE 5 — Nutrição: 5A auditoria
```

---

## 1. Executive summary

A Nutrição **já existe e está ativa** no mobile, principalmente em `lib/features/nutrition/**`, com dual-coleção Firestore e múltiplas entradas de UI.

Existem **duas camadas paralelas**:

| Camada | Estado real |
|--------|-------------|
| **Operacional atual** | UI + `NutritionService` + dual-write/read + AI callable |
| **Health v1 domain (alvo)** | Models `NutritionPlan` / `MealLog` / `SupplementLog` — **sem I/O de produção** |

**Achados centrais:**

1. Uma refeição do usuário gera **2 documentos** (`feeding_events` + `feedings`, mesmo ID) — dual-write sequencial **não atômico**.
2. Dual-read merge/dedupe por `docId` (última escrita no mapa vence se IDs iguais).
3. Mobile **ainda pode escrever plano** via `addPrescription` (método service + Rules abertas), embora **nenhuma UI** chame o método.
4. Shell Health v1 aba **Nutrição = placeholder**; UI real vive no prontuário legado, perfil, turno, hub e `NutritionFullScreen`.
5. Paths v1 documentados (`nutrition_plans`, `meal_logs`, `supplement_logs`) **não existem** em Rules nem em código de escrita/leitura.
6. Suplemento operacional = **cadastro “em uso”**, não log de administração pontual do Domain Model.
7. Timeline Health v1 **não** usa projeção `health_timeline` para refeições; lê dual-coleção em coexistência.
8. Summary v1 lê refeições/plano via `NutritionService` (legado operacional), **não** via `NutritionViewModel`.

**Direção de produto já aprovada (Domain Model):**

```text
WEB DEFINE O PLANO
MOBILE EXECUTA (refeições / suplementos)
```

**Conclusão:** Fase 5 não “cria Nutrição do zero”; **alinha o operacional ao contrato Health v1** sem perda de dados.

---

## 1.1 Achados de migração semântica (complemento 5B)

Estes findings **não** foram corrigidos em 5A; foram formalizados antes das decisões 5B.

### 1.1.1 Suplemento legado ≠ SupplementLog — MAJOR DE MIGRAÇÃO SEMÂNTICA

```text
nutrition_supplements  ≠  supplement_logs
```

| Modelo | Representa |
|--------|------------|
| `nutrition_supplements` (ops) | **Suplemento em uso** — regime contínuo, `started_at` / `ended_at`, status `em_uso` |
| `SupplementLog` (v1) | **Administração pontual** efetivamente realizada (`administered_at`, dose+unit) |

```text
NÃO executar backfill direto
nutrition_supplements → supplement_logs
```

Isso inventaria administrações históricas que **nunca** foram registradas.

Classificação: **MAJOR DE MIGRAÇÃO SEMÂNTICA**.

> **Pós-auditoria 5B:** decisões de ocorrência (`meal_occurrence_id`), plano futuro, autoridade de slot e invariantes de quantidade estão em
> `HEALTH_V1_PHASE_5B_NUTRITION_CANONICAL_DECISIONS.md` (D39–D42).
> Backfill de refeição legada: **sem** `meal_occurrence_id` artificial.

### 1.1.2 MealLog operacional não sustenta a UX oferecido × consumido

O operacional grava apenas:

```text
amount_grams
```

Não diferencia:

```text
quantidade oferecida
quantidade consumida
aceitação (full / partial / refused)
```

A UX Health aprovada exige essa distinção.

**Não assumir automaticamente:**

```text
amount_grams legado = offered_grams = consumed_grams
```

Interpretação e backfill devem seguir decisão 5B (D10).

### 1.1.3 Plano atual sem refeições planejadas individuais

Operacional:

```text
amount_grams_per_day + meals_per_day
```

**Não** basta para derivar deterministicamente:

```text
Refeição 07:00 — concluída
Refeição 19:00 — pendente
```

Contrato alvo precisa de **slots/meal_schedule** com identidade estável (decisão 5B D5).

### 1.1.4 Fotos legadas — coexistência obrigatória

Campo operacional existente:

```text
photo_balance_url
```

+ Storage `dogs/{dogId}/feeding_photos/{fileName}`.

O alvo tende a `attachment_refs` / HealthDocument.

Regras de migração:

* **não** perder a URL legada;
* **não** materializar parcialmente `HealthDocument` só para a foto;
* estratégia explícita em 5B (D25/D26).

---

## 2. Git / preflight

| Item | Valor |
|------|--------|
| Branch | `feature/health-v1-foundation` |
| HEAD completo | `c8893ed0497623956ab1390da4c020d137268854` |
| Mensagem | `docs(health): close preventive schedule final audit` |
| Tracking | up to date origin |
| Divergência | `0/0` |
| Temp Gate 5 | `temp/gate5_ui_e2e_screenshots/` removido (só screenshot transitória) |
| Alteração local | apenas este relatório |
| Commit / push / deploy | **NÃO** |

---

## 3. Files inventory

Para cada arquivo: responsabilidade, consumidores, estado, classificação.

### 3.1 `lib/features/nutrition/**`

| Arquivo | Responsabilidade | Consumidores | Estado | Classificação |
|---------|------------------|--------------|--------|---------------|
| `data/nutrition_service.dart` | CRUD dual feedings/prescriptions; supplements; foto Storage | VM; HealthSummaryNutritionReader; (indireto) AI via dados | Ativo | **ATIVO CANÔNICO** (operacional) |
| `data/nutrition_ai_service.dart` | Callable AI + DTO insight | `DogHealthProntuarioScreen` aba nutrição | Ativo | **ATIVO CANÔNICO** (feature AI) |
| `domain/feeding.dart` | Model refeição + soft delete + divergência | Service, VM, UI, PDF, History, summary | Ativo | **ATIVO CANÔNICO** (operacional) |
| `domain/nutrition_prescription.dart` | Model plano/prescrição | Service, VM, UI, PDF, summary | Ativo | **ATIVO CANÔNICO** (operacional) |
| `domain/nutrition_supplement.dart` | Model suplemento em uso | Service, VM, UI registro | Ativo | **ATIVO CANÔNICO** (operacional; semântica ≠ v1 log) |
| `presentation/viewmodels/nutrition_viewmodel.dart` | Estado global: hoje, 90d, filtros, writes | main Provider; prontuário; full; history; shift; profile | Ativo | **ATIVO CANÔNICO** (estado UI) |
| `presentation/screens/feeding_registration_screen.dart` | Form refeição + suplemento | Hub; prontuário; full; shift quick; profile | Ativo | **ATIVO CANÔNICO** |
| `presentation/screens/nutrition_full_screen.dart` | Histórico 90d, conformidade, gráfico, PDF, CTA | Profile; timeline detail; deep nav | Ativo | **ATIVO CANÔNICO** |

### 3.2 Health v1 domain (alvo)

| Arquivo | Responsabilidade | Consumidores | Estado | Classificação |
|---------|------------------|--------------|--------|---------------|
| `health/domain/nutrition_plan.dart` | `NutritionPlan` + conflict policy | Testes domain | Sem I/O | **COMPATIBILIDADE** (alvo futuro) |
| `health/domain/health_v1_models.dart` (`MealLog`) | Agregado refeição v1 | LegacyNutritionAdapter; testes | Sem I/O prod | **COMPATIBILIDADE** |
| `health/domain/supplement_log.dart` | Log administração v1 | Testes (se houver) | Sem I/O prod | **COMPATIBILIDADE** |
| `health/domain/health_v1_enums.dart` (`MealPeriod`) | Periods canônicos + parse legado parcial | Adapters; domain | Ativo em parse | **COMPATIBILIDADE** |
| `health/domain/readiness_policy.dart` | `hasActiveNutritionPlan` flag | Policy + tests; **sem wiring runtime** | Domain only | **COMPATIBILIDADE** |

### 3.3 Coexistência / summary / timeline

| Arquivo | Responsabilidade | Consumidores | Estado | Classificação |
|---------|------------------|--------------|--------|---------------|
| `health_summary_nutrition_reader.dart` | Alimentação hoje via NutritionService | CoexistenceHealthSummarySource | Ativo | **COMPATIBILIDADE** |
| `health_summary_recent_records_reader.dart` | Recentes dual feedings dia | Summary | Ativo | **COMPATIBILIDADE** |
| `coexistence_health_summary_source.dart` | Orquestra summary | Health v1 entry | Ativo | **COMPATIBILIDADE** |
| `firestore_timeline_readers.dart` | Readers feeding_events + feedings | Coexistence timeline | Ativo | **COMPATIBILIDADE** / dual |
| `health_timeline_mappers.dart` (`mapFeeding`) | Entry meal dual-source | Timeline readers | Ativo | **COMPATIBILIDADE** |
| `coexistence_health_timeline_source.dart` | Multi-source até projeção canônica | Timeline screen | Ativo | **COMPATIBILIDADE** (ponte) |
| `legacy_health_adapters.dart` (`LegacyNutritionAdapter`) | feeding map → MealLog | Pipeline legado/migração | Ativo em foundation | **COMPATIBILIDADE** |
| `health_timeline_detail_target.dart` (`NutritionHistoryTarget`) | Navegação detail | Resolver + entry | Ativo | **COMPATIBILIDADE** |
| `health_timeline_detail_resolver.dart` | feeding* → NutritionFullScreen | Timeline navigate | Ativo | **COMPATIBILIDADE** |

### 3.4 UI integradores externos

| Arquivo | Responsabilidade | Consumidores | Estado | Classificação |
|---------|------------------|--------------|--------|---------------|
| `main.dart` | Provider global NutritionViewModel | App root | Ativo | **ATIVO CANÔNICO** (wiring) |
| `dog_health_prontuario_screen.dart` | Aba Nutrição + hub + AI + registro | Navegação saúde legada | Ativo | **ATIVO CANÔNICO** (UI) |
| `health_v1_entry_screen.dart` | Shell: summary/timeline/agenda + **placeholder nutrição** | Health v1 | Ativo parcial | **ATIVO LEGADO** shell nutrição = placeholder |
| `health_type_selector_screen.dart` | Hub “Nutrição” → callback registro | Prontuário | Ativo | **ATIVO CANÔNICO** |
| `health_summary_dashboard.dart` + `health_summary_nutrition_card.dart` | Card ALIMENTAÇÃO HOJE | Shell resumo | Ativo | **COMPATIBILIDADE** (read v1) |
| `k9_profile_page.dart` | Card nutrição + full + registro | Perfil | Ativo | **ATIVO CANÔNICO** |
| `active_shift_quick_actions.dart` | Atalho registrar | Turno | Ativo | **ATIVO CANÔNICO** |
| `active_shift_dashboard_screen.dart` | loadForDog + loadFullHistory | Turno | Ativo | **ATIVO CANÔNICO** |
| `active_shift_today_section.dart` | Pulso 7d conta feedings | Turno | Ativo | **ATIVO CANÔNICO** |
| `history_data_loader.dart` / HistoryScreen | Histórico unificado nutrition entries | Histórico global/prontuário | Ativo | **ATIVO LEGADO** (composição cliente) |

### 3.5 Core / backend / rules

| Arquivo | Responsabilidade | Consumidores | Estado | Classificação |
|---------|------------------|--------------|--------|---------------|
| `core/services/pdf_generator/nutrition_pdf.dart` | PDF nutricional | NutritionFullScreen | Ativo | **ATIVO CANÔNICO** |
| `core/services/audit_service.dart` | Inline audit_trail builder | NutritionService | Ativo (inline only em nutrição) | **ATIVO CANÔNICO** |
| `core/services/storage_service.dart` | Upload imagem | NutritionService foto | Ativo | **ATIVO CANÔNICO** |
| `functions/src/index.ts` (`generateNutritionAiInsight` + loaders) | AI insight | NutritionAiService | Ativo | **ATIVO CANÔNICO** |
| `firestore.rules` (paths nutrition) | Client R/W audited | Runtime | Ativo | **ATIVO CANÔNICO** (regras abertas demais p/ plano) |
| `storage.rules` (`feeding_photos`) | Foto balança | Upload | Ativo | **ATIVO CANÔNICO** |
| `firestore.indexes.json` | — | — | Sem índices compostos nutrition | **INCERTO**/n/a (queries single-field) |

### 3.6 Testes

| Arquivo | Estado | Classificação |
|---------|--------|---------------|
| `test/features/health/domain/nutrition_plan_test.dart` | Ativo domain | **COMPATIBILIDADE** |
| `test/features/health/domain/readiness_policy_test.dart` | flag plan | **COMPATIBILIDADE** |
| Testes service/VM/UI nutrition | **Ausentes** | **MORTO / SEM ENTRADA** (gap) |

### 3.7 Documentação / mockups (referência)

| Item | Classificação |
|------|---------------|
| Domain Model §§2.7–2.9, Schema §§2.8–2.10, Permission Matrix | **CANÔNICO DOCUMENTAL** (alvo) |
| ADR-006 mapa feeding→meal_logs etc. | **CANÔNICO DOCUMENTAL** (migração) |
| Mockups `03-Nutrição - Hoje`, `04-Registrar Alimentação`, `plano alimentar` | Referência visual |
| `HEALTH_MODULE_AUDIT.md` | Histórico; revalidado por 5A |

**Nada apagado nesta fase.**

---

## 4. Navigation entry points

| # | Origem | Tela destino | dogId | Fluxo de estado | Read | Write | Notas |
|---|--------|--------------|-------|-----------------|------|-------|-------|
| E1 | `DogHealthProntuarioScreen` aba **Nutrição** | Conteúdo inline + AI + CTA registro | dog do prontuário | `loadForDog` + `loadFullHistory` via `_ensureNutritionLoaded` | Sim | Via E2 | **UI real principal legada** |
| E2 | Prontuário → Hub `HealthTypeSelectorScreen` → “Nutrição” | `FeedingRegistrationScreen` | dog do hub | Após save: forceReload + full history | — | **Sim** meal/supplement | Hub de registros |
| E3 | Prontuário CTA / FAB registro | `FeedingRegistrationScreen` | dog | igual E2 | — | **Sim** | Duplicata de E2 |
| E4 | Health v1 Shell aba **Nutrição** | `HealthShellSectionPlaceholder` | shell dog context | **Nenhuma** tela real | Mensagem “em construção” | **Não** | Card resumo já lê dados reais |
| E5 | Health v1 Resumo → “Abrir Nutrição” / “Registrar alimentação” | **Só muda seção shell** → placeholder E4 | shell dog | `_selectSection(nutricao)` | Summary card lê NutritionService | Write **não** abre form real | **Rota quebrada / incompleta** |
| E6 | Health v1 Timeline entry type meal | `NutritionFullScreen(dog)` | dog da entry (preferido) | loadForDog + full history | Sim | CTA → E7 | Bridge coexistência |
| E7 | `NutritionFullScreen` sticky CTA | `FeedingRegistrationScreen` | dog da tela | pop + stream | — | **Sim** | |
| E8 | `K9ProfilePage` card nutrição | `NutritionFullScreen` | widget.dog | load on init | Sim | via E7 | |
| E9 | `K9ProfilePage` atalho registro | `FeedingRegistrationScreen` | widget.dog | — | — | **Sim** | |
| E10 | `ActiveShiftQuickActions` | `FeedingRegistrationScreen` | active dog | shift context | — | **Sim** | |
| E11 | `ActiveShiftDashboard` load | (sem tela) | activeDogId | loadForDog + full history | Dados p/ pulso | Não direto | |
| E12 | `ActiveShiftTodaySection` pulso | (display only) | VM state | history+today feedings | Contagem 7d | Não | |
| E13 | `HistoryScreen` / prontuário history mode | entries nutrition | active shift dog | loadForDog + full history | Sim | Não | Fonte VM |
| E14 | Deep link / named routes dedicadas nutrition | **Não encontrado** | — | — | — | — | Sem rota nomeada isolada |

### Rotas duplicadas (mesma função)

| Função | Entradas duplicadas |
|--------|---------------------|
| Registrar alimentação/suplemento | E2, E3, E7, E9, E10 (todas → `FeedingRegistrationScreen`) |
| Ver histórico nutricional | E1 (parcial), E6, E8 → full screen / aba |
| “Abrir nutrição” no shell v1 | E4/E5 **placeholder** vs E1 real — **divergência de produto** |

---

## 5. Domain models

### 5.1 `Feeding` (operacional)

| Aspecto | Valor |
|---------|--------|
| Path comment no código | `/dogs/{dogId}/feedings/{id}` (desatualizado: primary write é `feeding_events`) |
| Campos | `id?`, `period` (string PT), `amountGrams`, `prescriptionAtTime`, `divergencePercent`, `divergenceReason?`, `photoBalanceUrl?`, `observations?`, `fedAt`, `fedBy`, `auditTrail`, soft delete |
| Required em prática | period, amount, prescription snapshot, divergence, fedAt, fedBy |
| Serialização | snake_case Firestore: `amount_grams`, `prescription_at_time`, `divergence_percent`, `photo_balance_url`, `fed_at`, `fed_by`, … |
| Enums | period **não tipado**: `'manha'\|'almoco'\|'noite'` |
| Derivados | `isConform` ⇔ `\|divergence\| <= 10`; `calculateDivergence` static |
| Autoria | `fed_by` (+ `created_by` no write service) |
| Timestamps | `fed_at` cliente; `created_at`/`updated_at` server |
| Soft delete | `deleted_at`, `deleted_by`, `delete_reason`/`deleted_reason` |
| schema_version | **Ausente** |
| audit | `audit_trail` inline array |

### 5.2 `MealLog` (Health v1 domain)

| Aspecto | Valor |
|---------|--------|
| Campos | `id`, `dogId`, `period` (`ParsedHealthEnum<MealPeriod>`), `amountGrams`, `fedAt`, `recordedBy`, `schemaVersion` |
| Required | todos acima |
| Opcionais domain model doc | plan_id, prescription_amount, divergence, attachments, observations — **ainda não no class MealLog minimal** |
| Serialização runtime | **sem toJson prod** |
| Autoria | `RecordedBy` |
| Soft delete | schema doc sim; class minimal não |
| Validação | amount > 0; fed_at not future via `validateFedAt` |

### 5.3 `NutritionPrescription` (operacional)

| Aspecto | Valor |
|---------|--------|
| Campos | amountGramsPerDay, foodType, mealsPerDay, vetName/Crmv/Institution, laudoPdfUrl, vigentFrom/Until, hydrationNotes, notes, audit, soft delete |
| Derivado | `amountPerMeal` = round(day/meals) |
| Vigência | `isVigentAt(date)` |
| schema_version | **Ausente** |
| status active/superseded | **Ausente** (só vigent_until) |

### 5.4 `NutritionPlan` (v1 domain)

| Aspecto | Valor |
|---------|--------|
| Status enum | active / superseded / cancelled |
| Campos ricos | hydrationMl, specialInstructions, professional, sourceDocument, attachmentRefs, supplementIds, recordedBy, schemaVersion |
| Conflict policy | >1 active por dogId |

### 5.5 `NutritionSupplement` (operacional)

| Aspecto | Valor |
|---------|--------|
| Campos | name, dose (string), startedAt, endedAt?, status (`em_uso` default), notes, createdBy, audit, soft delete |
| Ativo | `!deleted && endedAt==null && status != 'suspenso'` |
| **Não é** dose unitária numérica nem administered_at |

### 5.6 `SupplementLog` (v1 domain)

| Aspecto | Valor |
|---------|--------|
| Administração pontual | supplementName, dose numérica, unit enum, administeredAt, recordedBy, schemaVersion |
| Opcionais | notes, batchNumber, protocolId, nutritionPlanId |

### 5.7 `NutritionAiInsight` (DTO resposta)

Campos summary, recommendation_level, food_adjustment, listas, source_summary, used_ai, model, period_days — **não** é agregado canônico de domínio.

### 5.8 Inconsistências Dart ↔ Firestore esperado

| Item | Inconsistência |
|------|----------------|
| Primary path Feeding | Comment diz `feedings`; write primary `feeding_events` |
| Period | PT strings vs MealPeriod EN; parser legado só mapeia `manha`/`noite` (não `almoco`) |
| Prescription status | v1 tem status; operacional usa só vigent_until |
| schema_version | v1 exige; operacional não grava |
| recorded_by | v1 VO; operacional fed_by/created_by string |
| Supplement semantics | contínuo vs log |
| MealLog incompleto vs Domain Model §2.8 opcionais | gap model foundation |

---

## 6. Firestore paths

### 6.1 `dogs/{dogId}/feeding_events/{id}`

| Aspecto | Evidência |
|---------|-----------|
| Writers | Mobile `NutritionService.addFeeding`, `updateFeedingPhoto` |
| Readers | dual-read service; timeline; summary recentes; CF AI; History via VM |
| Queries | `fed_at` range + orderBy desc; optional limit |
| Indexes | single-field (implícito) |
| Rules | read: signedIn+canAccessDogRecord; create: access+canCreateAuditedRecord; update: access+canUpdateAuditedOrSoftDelete; delete: false |
| Schema | ver Feeding |
| Volume | inferível: 1+ por refeição/dia/cão; dual com feedings |
| Status | **CANÔNICO OPERACIONAL** |

### 6.2 `dogs/{dogId}/feedings/{id}`

| Aspecto | Evidência |
|---------|-----------|
| Writers | Dual-write espelho (mesmo id) |
| Readers | Dual-read merge |
| Queries | iguais a feeding_events |
| Rules | iguais |
| Status | **LEGADO ESPELHO** |

### 6.3 `dogs/{dogId}/nutritional_prescriptions/{id}`

| Writers | `addPrescription` (mobile service; sem UI) + possivelmente Web externo (fora repo) |
| Readers | getActive primary; history; CF AI |
| Queries | `vigent_from <= now` order desc limit 1; order history |
| Rules | client create/update allowed (audited) |
| Status | **CANÔNICO OPERACIONAL de plano** |

### 6.4 `dogs/{dogId}/nutrition_prescriptions/{id}`

| Writers | Dual-write se addPrescription |
| Readers | Fallback active + merge history |
| Status | **LEGADO FALLBACK** |

### 6.5 `dogs/{dogId}/nutrition_supplements/{id}`

| Writers | Mobile addSupplement |
| Readers | VM, CF AI |
| Queries | orderBy started_at desc |
| Rules | client create/update |
| Status | **CANÔNICO OPERACIONAL** (semântica em uso) |

### 6.6 `dogs/{dogId}/nutrition_ai_insights/{id}`

| Writers | Admin SDK callable only |
| Readers cliente | **Nenhum** (sem match Rules → deny-all) |
| Status | **ATIVO** backend-only |

### 6.7 Paths alvo documentados **sem runtime**

```text
nutrition_plans / meal_logs / supplement_logs
```

- Sem matches em `firestore.rules`
- Sem writers/readers mobile
- Status: **ALVO DOCUMENTAL / NÃO MATERIALIZADO**

### 6.8 Outros paths nutricionais no código?

Busca global `collection(...)` + rules: **somente** os paths acima. Nenhum outro path nutrition/meal/feeding além dos listados.

---

## 7. Meal write path

### Fluxo

```text
FeedingRegistrationScreen._save
  → NutritionViewModel.addFeedingWithPhoto
    → NutritionService.addFeeding
         1) feeding_events.doc().set(data)     // id auto
         2) feedings.doc(mesmoId).set(data)    // espelho
    → se photo:
         upload Storage dogs/{dogId}/feeding_photos
         updateFeedingPhoto merge dual (photo_balance_url + audit)
```

### Respostas precisas

| Pergunta | Resposta |
|----------|----------|
| Quantos docs por ação? | **2** documentos Firestore (sempre dual-write no create). +0/1 objeto Storage se foto. + merge updates se foto ok |
| Mesmo ID? | **Sim** — `legacy.doc(docRef.id)` |
| Ordem | primary `feeding_events` **depois** `feedings` |
| Atomicidade | **Não** — dois `await set` sequenciais; sem batch/transaction |
| 1ª ok, 2ª falha | Doc canônico existe; espelho ausente; dual-read ainda enxerga via primary |
| Audit | Inline `audit_trail: [created]` em ambos se 2ª ok; **não** grava `auditLogs` collection via `AuditService.log` |
| Foto | Após create; falha de upload **não** reverte feeding (VM engole erro) |
| Retry / offline | Sem idempotency key; offline depende do SDK Firestore; risco de duplo submit UI se usuário repetir |
| Duplicação | Possível se double-tap (dois ids novos) |
| Dedupe leitura | Por doc id |

### Risco

**MAJOR** — dual-write não atômico + sem idempotência + foto pós-fato.

**Não corrigido nesta rodada.**

---

## 8. Meal read path

### `watchTodayFeedings`

- Collections: **ambas** `feeding_events` + `feedings`
- Range: startOfDay local → endOfDay local (`DateTime.now()` device)
- Merge: streams paralelos; emite união em cada evento
- Dedupe: mapa por `item.id ?? fedAt.microseconds`
- Precedência: **última escrita no loop** sobre mesmo key (ordem primary depois legacy no expand de get; no stream, quem emitiu por último no emit() depende da ordem de chegada)
- Soft-delete: filtrado `!isDeleted` no client
- Erro stream: `onError` → VM zera `_todayFeedings = []` (**empty mascara erro**)
- Ordenação: `fed_at` desc
- Timezone: **device local** para janela “hoje”
- Paginação: **nenhuma** (dia inteiro)

### `getFeedings` / histórico 90d

- Dual Future.wait; dedupe; take(limit) se informado
- `loadFullHistory`: from = now-90d, **sem limit**
- Erro: catch → listas vazias (**empty mascara erro**)

### Timeline dual-read

- Readers separados; entry id unificado `feeding:{docId}` para cursor/dedupe multi-source
- Precedência: paginator multi-source (não “last map wins” simples do service)

### Summary recentes

- Dual snap limit 10 cada; dedupe `byId[doc.id]` (segundo snap sobrescreve)

### Risco dual-count

Se dual-write **parcial** (só uma collection), contagem correta (1).
Se dual-write **completo**, dedupe por id evita dupla contagem **se ids iguais**.
Se histórico legado tiver docs **só em uma collection com ids diferentes**, podem aparecer 2 entradas reais distintas — esperado.

---

## 9. Plans

### Decisão produto

```text
WEB DEFINE
MOBILE CONSULTA E EXECUTA
```

### Métodos mobile que tocam plano

| Método | Capacidade | UI caller? |
|--------|------------|------------|
| `getActivePrescription` | read | Sim (VM load) |
| `getPrescriptionHistory` | read | Sim (full history) |
| **`addPrescription`** | **create + encerra anterior (vigent_until)** dual-write | **NÃO** |

### `addPrescription` comportamento

1. Busca active
2. Se existe: merge `vigent_until = new.vigentFrom` em canônico + legado
3. Cria novo doc dual-write com audit created

### Campos de plano operacional mapeados

| Conceito | Campo |
|----------|-------|
| objetivo / alimento | `food_type` |
| quantidade diária | `amount_grams_per_day` |
| refeições/dia | `meals_per_day` |
| horários fixos | **não modelados** |
| suplementos previstos | **não no prescription** (supplements collection separada) |
| responsável vet | vet_name, vet_crmv, vet_institution |
| laudo | laudo_pdf_url |
| hidratação | hydration_notes (texto) |
| vigência | vigent_from / vigent_until |
| versão schema | **ausente** |
| status superseded | implícito via vigent_until, não enum |

### O mobile ainda consegue escrever plano?

```text
SIM — via NutritionService.addPrescription + Rules create/update abertas.
```

**Classificação: MAJOR risco arquitetural** (capability real sem UI, viola “Web define” se chamada ou se cliente malicioso).

**Não removido nesta rodada.**

---

## 10. Active plan resolution

### Algoritmo real (`getActivePrescription`)

```text
1. Query nutritional_prescriptions:
     where vigent_from <= now
     orderBy vigent_from DESC
     limit 1
2. Se vazio → mesma query em nutrition_prescriptions (legado)
3. Se vigent_until != null && now > vigent_until → return null
4. Soft-delete: primary path NÃO filtra isDeleted no primeiro branch
   (legado _getActivePrescriptionFrom filtra isDeleted)
```

| Cenário | Comportamento |
|---------|---------------|
| Múltiplos planos “ativos” (sem until) | **Último vigent_from** vence — **não** há status active |
| Plano futuro (vigent_from > now) | Não elegível na query `<= now` |
| Plano expirado | null após check until |
| Ausência | null |
| Timezone | `DateTime.now()` **device** vs Timestamp server — **sem TZ explícito do plano** |

### Regra canônica?

**Não.** É **convenção implícita** de query + until, não máquina de estados `active/superseded`.

---

## 11. Planned vs executed meals

### Estado atual do conceito

```text
plano (prescription)
  → amount_grams_per_day + meals_per_day
  → amountPerMeal derivado
  → UI sugere quantidade e period por hora do dia
  → Feeding executado com snapshot prescription_at_time + period string
  → consumo = soma amount_grams do dia
```

### Vínculo persistido meal ↔ planned meal?

```text
NÃO.
```

- Não há `plan_id` / `planned_meal_id` no `Feeding` operacional.
- Correspondência é **inferida** por:
  - snapshot numérico `prescription_at_time` no momento do registro;
  - `period` escolhido pelo usuário (manha/almoco/noite);
  - não por horário canônico de refeição planejada.

### Mapeamento conceitos

| Conceito | Estado atual |
|----------|--------------|
| MealPeriod | Operacional PT string; v1 enum EN |
| Horário | `fed_at` livre (agora / -5 / -15 / custom) |
| Qtd oferecida vs consumida | **Um único** `amount_grams` (não distingue oferecido/consumido) |
| Aceitação / recusa / parcial | **Não modelados** |
| Observações | `observations` na refeição |
| Foto | `photo_balance_url` |
| Autoria | `fed_by` |

**Nenhum schema novo inventado nesta auditoria.**

---

## 12. Consumption calculations

| Métrica | Como | Classificação |
|---------|------|---------------|
| Meta diária | `prescription.amountGramsPerDay` | **persistido** no plano; lido |
| Meta/refeição | `amountPerMeal` round division | **derivado** |
| Consumido hoje | soma `amount_grams` feedings do dia | **derivado** (recalculável) |
| Progresso dia | consumed / prescribedPerDay | **derivado** |
| Divergência refeição | `(amount - prescriptionAtTime)/prescriptionAtTime * 100` | **persistido** no doc (também recalculável se snapshot ok) |
| Conformidade refeição | `\|div\| <= 10` | **derivado** |
| Conformidade % dia | count conform / total today | **derivado** |
| Conformidade 90d | mesmo sobre historyFeedings | **derivado** |
| % meta (summary) | consumed + plannedAmount | **derivado** no reader |
| Oferecido vs consumido | **não existe** | n/a |
| Dual-count risk | mitigado por dedupe id se dual-write completo | **aceito com ressalva** |

Ambíguo: se `prescription_at_time=0` (sem plano), divergência 0 e “conformidade” sem sentido (UI força `_isCompliant=false` sem plano).

---

## 13. Supplements

### Collection `nutrition_supplements`

| Pergunta | Resposta atual |
|----------|----------------|
| Prescrição ou execução? | **Híbrido confuso**: cadastro “em uso” (mais prescrição/estado) com create pelo condutor na tela de “registrar” |
| Status ativo? | `status` string default `em_uso`; `isActive` helper |
| Frequência? | **Não** |
| Dose? | string livre |
| Início/fim? | `started_at`, `ended_at?` |
| Administração registrada? | **Não** como log pontual |
| Quem cria? | Mobile UI (condutor) via `addSupplement` |
| Quem altera? | Update Rules abertas; **sem UI de edit/end** encontrada |
| Timeline? | **Não** — timeline readers não incluem nutrition_supplements |
| Nutrição Hoje (summary)? | **Não** no card summary |
| Histórico nutrition full? | Supplements carregados no VM full history, **UI full screen foca refeições/prescrição** (supplements no prontuário) |
| AI? | Sim, CF carrega até 30 |

### Separação conceitual

| Conceito | Código atual | Alvo v1 |
|----------|--------------|---------|
| Suplemento planejado / em uso | `NutritionSupplement` | parcialmente NutritionPlan.supplementIds / outro |
| Suplemento administrado | **não existe** | `SupplementLog` |

**MAJOR:** conceitos misturados.

---

## 14. Observations

| Forma | Existe? | Onde |
|-------|---------|------|
| Observação da refeição | **Sim** | `Feeding.observations` / campo form |
| Motivo divergência | **Sim** | `divergence_reason` |
| Notas do plano | **Sim** | `prescription.notes`, `hydration_notes` |
| Notas do suplemento | **Sim** | `notes` (UI usa como “motivo”) |
| Observação diária standalone | **Não** | — |
| Entidade observation nutrition | **Não** | — |
| health_events para nutrition note | **Não** no fluxo nutrition | — |

**Conclusão:** observações **vivem dentro** da refeição/plano/suplemento; sem registro diário próprio.

---

## 15. Nutrition history

| Consumidor | Source | Paginação | Dual-read | Supplements | Plano | Observações |
|------------|--------|-----------|-----------|-------------|-------|-------------|
| `NutritionFullScreen` | VM `getFeedings` 90d + prescription history + supplements load | Não (load 90d) | Sim | load sim; lista principal = feedings | seção prescrição | por item feeding |
| Prontuário aba Nutrição | VM today + prescription + supplements | — | stream dual | lista supplements | card plano | — |
| HistoryScreen global | VM historyFeedings (fallback today) | Não | via VM | **Não** entries | não | details map |
| Health Timeline v1 | dual feeding collections multi-source | **Sim** paginator | Sim (id unificado) | **Não** | **Não** | subtitle gramas |
| Health Summary recentes | dual feedings dia limit 10 | limit limit | Sim | Não | Não | subtitle g |
| AI insight | CF dual feedings + prescription + supplements + weight + health + training | limits server | dual | sim | sim | compact |

---

## 16. Health timeline integration

| Pergunta | Resposta |
|----------|----------|
| Refeições projetam `health_timeline` canônica server? | **Não** — coexistência lê collections legadas |
| Suplementos projetam? | **Não** |
| Mudança de plano projeta? | **Não** |
| Observação nutricional projeta? | **Não** (só se embutida no meal map) |
| Dependência exclusiva histórico legado? | Timeline v1: dual feedings; HistoryScreen: **sim** via NutritionViewModel |

Tap meal → `NutritionHistoryTarget` → `NutritionFullScreen` (UI legada).

---

## 17. Health summary integration

| Bloco | Source | VM legado? |
|-------|--------|------------|
| ALIMENTAÇÃO HOJE | `HealthSummaryNutritionReader` → **NutritionService** getFeedings dia + getActivePrescription | **Não** usa NutritionViewModel |
| Registros recentes feeding | dual-read direto Firestore | Não |
| Plano ativo no summary | via prescription no reader (plannedAmount / mealsPlanned) | Não |
| Atenção nutricional | sem score IPO; attention items genéricos se hint “nutri” | — |
| Erros/offline | reader retorna `unavailable` (não empty) | Melhor que VM |
| Shell CTAs | navegam para **placeholder** seção nutrição | **gap UX** |

**Conclusão:** Summary v1 já usa service operacional; shell write/nav ainda não tem tela v1.

---

## 18. NutritionViewModel

| Aspecto | Evidência |
|---------|-----------|
| Keyed por dogId | `_activeDogId`; early return se mesmo dog e !forceReload |
| Global singleton | Provider root `main.dart` — **um** VM app-wide |
| Troca rápida K9 | risco stale se caller não forceReload; streams antigos cancelados em novo load |
| Cancel streams | `_feedingsSub?.cancel()` no load e dispose |
| Stale | history/prescription podem ficar de dog anterior se só stream atualiza parcialmente |
| Loading | `_loading`, `_historyLoading` flags simples |
| Error | catch → empty lists + debugPrint (**empty silencioso**) |
| Offline | não tratado explicitamente |
| Merge | delegado ao service |
| Lifecycle | dispose cancela sub |
| Classificação recomendada | **REFATORADO / LEGACY ADAPTER** — reutilizar conceitos, não como store canônico v1 |

---

## 19. NutritionService — mapa de métodos

| Método | Chamado por | Ativo UI? | Escreve | Auth real | Audit | Atomicidade | Risco |
|--------|-------------|-----------|---------|-----------|-------|-------------|-------|
| `watchTodayFeedings` | VM | Sim | — | Rules read | — | dual streams | empty error no VM |
| `getFeedings` | VM history; Summary reader | Sim | — | read | — | dual get | dual-count se ids ≠ |
| `addFeeding` | VM | Sim | dual feedings | client Rules | inline created | **não atômico** | MAJOR |
| `uploadFeedingPhoto` | VM with photo | Sim | Storage | storage Rules | — | — | órfãos se doc fail reverse n/a |
| `updateFeedingPhoto` | VM | Sim | dual merge | Rules update+audit | inline field | dual set merge | partial mirror |
| `getActivePrescription` | VM; Summary; (AI server próprio) | Sim | — | read | — | — | convenção implícita |
| `addPrescription` | **ninguém UI** | Código vivo | dual prescriptions + end previous | Rules **allow** | inline | multi set | **MAJOR arquitetural** |
| `getPrescriptionHistory` | VM full | Sim | — | read | — | dual merge | — |
| `calculateConformity` | (API service) | **pouco/não usado UI** (VM calcula local) | — | — | — | — | MINOR morto parcial |
| `getSupplements` | VM | Sim | — | read | — | — | — |
| `addSupplement` | VM | Sim | nutrition_supplements | Rules create | inline | single set | semântica |
| helpers `_get*` `_watch*` `_dedupe*` | internos | — | — | — | — | — | — |

**Mistura:** read/write/coexistência/storage/cálculo no mesmo service — candidato a **fatiar** na Fase 5.

---

## 20. Functions / AI

### `generateNutritionAiInsight`

| Aspecto | Valor |
|---------|--------|
| Tipo | `onCall` region `southamerica-east1`, timeout 60s, secret `GEMINI_API_KEY` |
| Auth | `requireAuth` + `requireDogRecordAccess` |
| Inputs | `dog_id`, `period_days` (clamp 7..max) |
| Lê | prescription dual, feedings dual, supplements, trainings, weight_records, health_events |
| Escreve | `nutrition_ai_insights/{autoId}`; update dog `audit_trail` + `updated_at` |
| Dual-write dependência | loaders dual-read com dedupe por id → **mitiga** dupla contagem se ids iguais |
| Fallback | `nutritionFallbackInsight` se Gemini falhar |
| Status produto | Ativo no prontuário aba Nutrição |
| Domain v1 | **fora** do core canônico; feature adjacente |

**Não alterar IA nesta fase.**

---

## 21. Firestore Rules

| Path | Read | Create | Update | Delete | Condição |
|------|------|--------|--------|--------|----------|
| `feedings/{id}` | signedIn && canAccessDogRecord | access && canCreateAuditedRecord | access && canUpdateAuditedOrSoftDelete | false | audited inline |
| `feeding_events/{id}` | idem | idem | idem | false | idem |
| `nutrition_prescriptions/{id}` | idem | **idem (cliente pode criar)** | idem | false | **conflita com Web define** |
| `nutritional_prescriptions/{id}` | idem | **idem** | idem | false | **conflita com Web define** |
| `nutrition_supplements/{id}` | idem | idem | idem | false | execução/estado |
| `nutrition_ai_insights` | **sem match → deny** | deny client | deny | deny | Admin only de facto |
| `meal_logs` / `nutrition_plans` / `supplement_logs` | **sem match** | — | — | — | não materializados |

### Confronto direção alvo

| Direção | Estado atual |
|---------|--------------|
| Plano: Web gerencia | **Rules mobile ainda permitem write** |
| Execução diária: Mobile | **Alinhado** (feedings/supplements) |
| Histórico auditável | inline audit_trail; hard delete false |
| Hard delete não | **Alinhado** |

---

## 22. Storage

| Aspecto | Valor |
|---------|--------|
| Path | `dogs/{dogId}/feeding_photos/{fileName}` |
| Create | canAccessDogRecord && canWriteImage(10) — image + ≤10MB |
| Read | signedIn && canAccessDogRecord |
| Update/Delete | **false** (imutável) |
| Ownership | por dogId path; sem ownership file-level extra |
| Upload ordem | **depois** do doc feeding; photo URL merge |
| Retry | sem protocolo app-level |
| Órfãos | foto upload sem doc: improvável (foto após doc); doc sem foto: comum se upload falha |
| MIME | image helpers storage |

**Não alterado nesta rodada.**

---

## 23. Audit trail

| Entidade | Quem | Quando | O que | Origem |
|-----------|------|--------|-------|--------|
| Refeição | `fed_by` = auth uid; `created_by` = fedBy; audit_trail created | create client timestamps + server created_at | payload feeding | Mobile client |
| Foto refeição | audit_trail updated field photo_balance_url | update | old/new url | Mobile |
| Plano | audit created/updated vigent_until | addPrescription | dual | Mobile service (sem UI) / Web? |
| Suplemento | created_by uid; audit created | create | payload | Mobile |
| AI | requested_by caller; dog audit_trail union | callable | insight doc | Backend |

### Inconsistências

```text
fed_by / created_by / recorded_by (v1) / audit_trail inline / auditLogs collection
```

- Nutrição **não** chama `AuditService.log` → **não** alimenta `auditLogs` canônico do painel (só inline array).
- AI grava entry no **dog** root audit_trail, não no meal.

---

## 24. Permissions

### Estado atual (implementação)

| Ação | Quem na prática |
|------|-----------------|
| Consultar plano | signedIn + canAccessDogRecord(dog) |
| Registrar alimentação | idem + create audited |
| Registrar suplemento | idem |
| Alterar/criar plano | **qualquer cliente com access+audit create/update** (Rules); UI mobile não expõe |

Capabilities `health.*` granulares da matriz **não** são enforced nestes matches Rules.

### Direção alvo (matriz Health v1 — sem inventar capability)

| Ação | Alvo documentado |
|------|------------------|
| Consultar plano | `health.read` |
| Registrar meal | `health.record_routine` |
| Registrar supplement log | `health.record_routine` |
| Gerir plano | `health.manage_nutrition_plan` **Web only** |

---

## 25. Legacy coexistence

| Agregado | CANÔNICO ATUAL (ops) | LEGADO | NOVO ALVO (docs) |
|----------|----------------------|--------|------------------|
| Refeições | `feeding_events` | `feedings` espelho | `meal_logs` |
| Planos | `nutritional_prescriptions` | `nutrition_prescriptions` | `nutrition_plans` |
| Suplementos | `nutrition_supplements` | — | `supplement_logs` (se semântica log) |

### Estratégia recomendada (não executar)

```text
1. Decidir: rename paths vs normalize-in-place (ver §28)
2. single-write canônico novo (ou path atual normalizado)
3. dual-read temporário de legado
4. backfill idempotente
5. paridade leitores (summary, timeline, history, AI, VM)
6. cutover writers
7. legacy read-only
8. remoção futura dual-write e paths mortos
```

---

## 26. Risks / Findings classification

### BLOCKER

*Nenhum bloqueador de auditoria.* (Há blockers potenciais de **implementação** se se tentar cutover sem fechar write de plano.)

### MAJOR

| ID | Finding |
|----|---------|
| M1 | Dual-write refeição não atômico |
| M2 | Mobile `addPrescription` + Rules abertas vs “Web define” |
| M3 | Semântica suplemento em uso ≠ SupplementLog administração |
| M4 | Models/periods/schema_version divergentes ops vs v1 |
| M5 | Shell v1 Nutrição placeholder; CTAs resumo não abrem UI real de write |
| M6 | VM mascara erro como empty |
| M7 | Plano ativo = convenção implícita, não status machine |
| M8 | **MAJOR DE MIGRAÇÃO SEMÂNTICA:** `nutrition_supplements` ≠ `supplement_logs` — proibido backfill direto de administração |
| M9 | `amount_grams` único não cobre offered/consumed/acceptance da UX alvo |
| M10 | Plano sem meal_schedule — impossível slots 07:00/19:00 |
| M11 | `photo_balance_url` exige estratégia de coexistência (não perder; não half-HealthDocument) |

### MINOR

| ID | Finding |
|----|---------|
| m1 | Comment Feeding path desatualizado |
| m2 | `calculateConformity` service subutilizado |
| m3 | Parser legado MealPeriod sem `almoco` |
| m4 | Sem testes feature nutrition |
| m5 | Active primary prescription não filtra soft-delete no branch principal |
| m6 | Global VM um dog |
| m7 | Nutrição não escreve `auditLogs` collection |

### DOCUMENTATION

| ID | Finding |
|----|---------|
| D1 | Paths v1 docs sem materialização Rules/código |
| D2 | Domain MealLog class incompleta vs §2.8 |
| D3 | Comment paths / ADR alinhados conceitualmente, runtime ainda dual |

### ACCEPTED LEGACY

| ID | Finding |
|----|---------|
| L1 | Dual-read feedings até cutover |
| L2 | Typo `vigent_*` consolidado em produção |
| L3 | AI insights backend-only sem Rules cliente |
| L4 | Threshold ±10% conformidade de produto |
| L5 | Foto imutável Storage |

---

## NOTA PÓS-5B

```text
NOTA PÓS-5B

As seções abaixo preservam a proposta produzida durante a auditoria 5A
antes do congelamento do contrato.

Elas são HISTÓRICAS e NÃO NORMATIVAS.

O contrato canônico vigente é:
HEALTH_V1_PHASE_5B_NUTRITION_CANONICAL_DECISIONS.md
D1–D42.

Em qualquer divergência, a Fase 5B e os documentos canônicos reconciliados prevalecem.
```

---

## 27. Proposed canonical contract

### Princípios (obrigatórios)

```text
Web define o plano
Mobile executa
single-write canônico
sem dual-write permanente
timeline é projeção
autoridade/auditoria confiáveis
estado por K9
erro ≠ empty silencioso
coexistência explícita com legado
```

### Recomendação de paths

**Preferência documental já aprovada (ADR-006 / Schema / Domain):**

```text
dogs/{dogId}/nutrition_plans/{planId}
dogs/{dogId}/meal_logs/{mealId}
dogs/{dogId}/supplement_logs/{logId}
```

**Justificativa para manter nomes documentados:**

- já estão no Domain Model, Schema, Permission Matrix, Test Strategy e ADR-006;
- separam semanticamente de prescriptions/feedings legados;
- Web e mobile podem migrar com coexistência dual-read.

**Alternativa de menor risco operacional (só se Web/backfill caros):**
normalizar schema **in-place** em `nutritional_prescriptions` / `feeding_events` / `nutrition_supplements` e renomear depois.
Isso **desvia** do canônico documental e deve ser decisão explícita 5B — **não recomendado como default** sem alinhamento Web.

### Contratos propostos (resumo)

#### NutritionPlan (Web write)

- status: active | superseded | cancelled
- food_type, amount_grams_per_day, meals_per_day
- vigent_from / vigent_until (preservar nome legado no adapter se necessário)
- recorded_by, schema_version
- professional?, source_document?, hydration_ml?, special_instructions?
- **Mobile: read-only**

#### MealLog (Mobile write)

- period: MealPeriod canônico
- amount_grams, fed_at (not future), recorded_by, schema_version
- plan_id?, prescription_amount_at_time?, divergence_*, observations?, attachment_refs?
- **single-write**; sem espelho permanente

#### SupplementLog (Mobile write) — *após decisão 5B*

- **Opção A (docs):** administração pontual
- **Opção B:** manter entidade “em uso” + logs futuros
Auditoria recomenda **decidir em 5B antes de write path novo**.

#### AI insights

- permanece feature auxiliar; não bloqueia contrato core.

### Writers

| Agregado | Writer |
|----------|--------|
| Plan | Web / Admin |
| Meal | Mobile (service ou callable — decisão 5B; 4E pattern se autoridade forte) |
| Supplement | Mobile |
| Timeline meal | projeção server (futuro); coexistência dual-read até lá |

---

## 28. Migration recommendation

```text
Fase 5B — decisões (paths, suplemento A/B, client vs callable, fechar Rules plano)
Fase 5C — domain/mappers/adapters dual-read
Fase 5D — single-write meal (+ supplement) canônico; dual-read legado
Fase 5E — UI: shell v1 real; mobile plan read-only; fechar addPrescription/Rules
Fase 5F — consumers: summary, timeline, history, AI, PDF, readiness flag
Fase 5G — backfill idempotente + paridade + cutover + gate confronto
```

Backfill:

| From | To |
|------|-----|
| feeding_events (+ feedings dedupe) | meal_logs |
| nutritional_prescriptions (+ fallback) | nutrition_plans (status derivado de vigent) |
| nutrition_supplements | supplement_logs **ou** entidade em uso se B |

**Não executar migração nesta rodada.**

### Dependências fora de escopo

| Dependência | Tratamento |
|-------------|------------|
| Peso (`weight_records`) | AI e readiness leem; **não migrar** (Fase 6) |
| Prontidão / IPO | flag `hasActiveNutritionPlan` apenas; **não** score (Fase 12) |

---

## 29. Gate plan for Phase 5

| Gate | Critério |
|------|----------|
| 5A | Esta auditoria revisada e decisões abertas listadas |
| 5B | Decisões produto/arquitetura assinadas |
| 5C | Read path coexistência verde + testes |
| 5D | Write meal single-write + zero dual permanente novo |
| 5E | UI shell + form; plan mobile read-only; Rules alinhadas |
| 5F | Consumers + AI dual-read ok; empty≠error |
| 5G | Emulator + confronto domain×backend×rules×UI; zero BLOCKER/MAJOR abertos de contrato |

---

## 30. Final recommendation

1. **Tratar Nutrição operacional atual como fonte viva** a coexistir, não descartar.
2. **Adotar contrato documental** `nutrition_plans` / `meal_logs` / `supplement_logs` salvo decisão 5B contrária justificada.
3. **Fechar write de plano no mobile** (código + Rules) assim que Web for writer exclusivo.
4. **Eliminar dual-write permanente** de refeições no cutover.
5. **Resolver semântica de suplemento** antes de implementar.
6. **Substituir/refatorar NutritionViewModel** para estado por K9 com error states reais.
7. **Completar shell v1 Nutrição** (hoje placeholder) para não mentir nos CTAs do Resumo.
8. **Não expandir** para Pesagem (Fase 6) nem Prontidão completa (Fase 12).

---

## Checklist de fechamento 5A

```text
[x] write path atual (dual feeding_events + feedings)
[x] onde existe dual-write
[x] como funciona dual-read / dedupe
[x] qual plano é ativo (query vigent_from + until)
[x] quem ainda consegue escrever plano (service+Rules; sem UI)
[x] como refeições/consumo são calculados
[x] como suplementos funcionam (em uso ≠ log)
[x] quais telas estão ativas (e placeholder shell)
[x] NutritionViewModel estado global / empty error
[x] NutritionService responsabilidades misturadas
[x] Rules matrix
[x] Storage feeding_photos
[x] timeline/resumo consumers
[x] coexistência e migração recomendada
[x] contrato canônico proposto
```

```text
## ✅ FASE 5A — AUDITORIA CONCLUÍDA

FASE 5A — AUDITORIA DE NUTRIÇÃO PRONTA PARA REVISÃO HUMANA

ZERO commit / push / deploy nesta rodada.
Nada apagado.
Implementação Fase 5 não iniciada.
```
