# Health v1.0 — Fase 3E-D — Runtime / APK (parcial 3E-D1)

## 1. Preflight

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `a1afa1213d7e174372674763aed56d09e69fcd06` |
| tracking | `origin/feature/health-v1-foundation` |
| divergência | `0/0` |
| working tree | 3E-A + 3E-B + 3E-C (+ este relatório 3E-D) **não commitados** |
| commits 3E | **nenhum** |
| APK staged/tracked | **não** |

Diff escopo: presentation timeline/entry, testes 3E, docs 3E. Sem data layer 3C.

## 2. Base auditada

| Base | Valor |
|------|--------|
| 3E-C veredito | **APROVADA PARA VALIDAÇÃO EM DISPOSITIVO** |
| Código de produção alterado nesta etapa | **não** |
| Build a partir de | working tree auditado 3E-A+B+C |

## 3. Validação pré-build

| Check | Resultado |
|-------|-----------|
| `flutter analyze` entry+timeline | **No issues found** |
| `flutter test` 3E-C audit | **16 passed** |

## 4. Build

| Item | Valor |
|------|--------|
| comando | `flutter build apk --debug --target-platform android-arm64` |
| Gradle | **✓ Built** `app-debug.apk` |
| flutter exit code | **0** |
| data/hora build | **2026-07-16 16:25:54** (local) |

## 5. APK origem

| Campo | Valor |
|-------|--------|
| caminho | `C:\Projetos\canil_gcm_mobile_chatgpt\canil-gcm\build\app\outputs\flutter-apk\app-debug.apk` |
| nome | `app-debug.apk` |
| tamanho | **256748516** bytes (~244,9 MB) |
| gerado | 2026-07-16 16:25:54 |
| SHA-256 | `436427B4B85D298A64C6BD2543EE2F08EAD5A650B99FE2CC0E6F08A2D6BC915F` |

## 6. APK destino Google Drive

| Campo | Valor |
|-------|--------|
| pasta | `G:\meu drive\apps k9` |
| nome | **`K9-Ops-Health-3E-D-debug.apk`** |
| caminho | `G:\meu drive\apps k9\K9-Ops-Health-3E-D-debug.apk` |
| tamanho | **256748516** bytes |
| SHA-256 | `436427B4B85D298A64C6BD2543EE2F08EAD5A650B99FE2CC0E6F08A2D6BC915F` |

## 7–8. Integridade da cópia

| Check | Resultado |
|-------|-----------|
| tamanho origem = destino | **True** |
| SHA-256 origem = destino | **True** |
| destino existe | **True** |

## 9. Artefato não versionado

- APK em `/build` (gitignore)
- Cópia no Google Drive **fora** do repositório
- `git status` sem APK staged/tracked

## 10. Estado pré-runtime

| Item | Status |
|------|--------|
| APK disponível no Drive | **sim** |
| instalado no celular | **PENDENTE** (usuário) |
| login real | **PENDENTE** |
| Histórico real | **PENDENTE** |

## 11. Checklist runtime (gates manuais)

| Gate | Status |
|------|--------|
| A — Primeira abertura | **PENDENTE** |
| B — Cão correto | **PENDENTE** |
| C — Dados reais | **PENDENTE** |
| D — Ordenação | **PENDENTE** |
| E — Quick filters | **PENDENTE** |
| F — Filtro avançado | **PENDENTE** |
| G — Nav peso | **PENDENTE** |
| H — Nav nutrição | **PENDENTE** |
| I — Nav vacinação | **PENDENTE** |
| J — Unsupported | **PENDENTE** |
| K — Paginação | **PENDENTE** (ou NÃO TESTÁVEL se dataset pequeno) |
| L — Footer | **PENDENTE** |
| M — FAB / bottom nav | **PENDENTE** |
| N — Responsividade | **PENDENTE** |
| O — Erros de console | **PENDENTE** |
| Offline real | **PENDENTE** / opcional |
| F1 cross-dog filtros contextuais | **PENDENTE** se fluxo permitir |

## 12. F1 residual (3E-C)

Filtros `caseId` / `professional` podem permanecer após troca de cão (contrato 3A `selectDog`). Observar no device se o app permitir troca de cão com Health vivo. **Não corrigir** nesta coleta.

## 13. Estado git

HEAD `a1afa12`. Working tree 3E-A+B+C + relatório 3E-D. **Sem commit/push.**

## 14. Classificação provisória (3E-D1)

# APK DISPONIBILIZADO — AGUARDANDO VALIDAÇÃO EM DISPOSITIVO

**Não** é “3E-D concluída”. Runtime manual = 3E-D2 (usuário no celular).

---

## Roteiro rápido (celular) — 3E-D1 (superseded)

1. Abrir Google Drive → pasta **apps k9**
2. Baixar/instalar **`K9-Ops-Health-3E-D-debug.apk`**
3. Login real → turno/binômio real → **Saúde** → aba **Histórico**
4. Validar gates A–N (e opcional offline / F1)
5. Retornar: PASS / FAIL / NÃO TESTÁVEL por gate + screenshots se possível

---

# Correção runtime de navegação — 3E-D2

## 1. Evidência do dispositivo (3E-D1 reteste)

Retorno manual do usuário no APK `K9-Ops-Health-3E-D-debug.apk`:

| Área | Resultado |
|------|-----------|
| Histórico abre / Firestore real / dados reais | **PASS** |
| Quick filters / avançados / períodos / empty filtrado | **PASS** |
| Shell / FAB / bottom nav / responsividade | **PASS** |
| **Gate G — Nav peso** | **FAIL runtime** |
| **Gate H — Nav nutrição** | **FAIL runtime** |
| **Gate I — Nav vacinação** | **FAIL runtime** |

Sintoma: cards related-history exibem affordance (chevron / tap), mas o destino **não abre** — usuário permanece no Histórico.

## 2. Diagnóstico (cadeia auditada)

```text
tap card
→ HealthTimelineEntryCard InkWell (onTap != null ⇔ chevron)
→ HealthTimelineView._tapFor / entryNavigable
→ HealthTimelineScreen._onEntryTap
→ HealthTimelineDetailResolver (allowlist)
→ HealthTimelineNavigationCoordinator
→ onNavigate (callback Entry)
→ HealthV1EntryScreen._onTimelineNavigate
→ resolve Dog(target.dogId)
→ Navigator.push → tela legado
```

Instrumentação debug `[TIMELINE_NAV]` adicionada nas etapas tap / resolver / coordinator / entry / dog / push / return.

## 3. Causa raiz

**Defeitos combinados no path de produção (não coberto pelos testes 3E-B/C):**

1. **Coordinator capturava `widget.onNavigate` só em `initState`**  
   O Entry passava closure nova a cada rebuild  
   (`(t) => _onTimelineNavigate(t, dogContext)`).  
   O `HealthTimelineScreen` (preservado no `IndexedStack` do shell) mantinha o callback da **primeira montagem**. Em rebuilds do Entry/shell, a identidade do callback divergia do widget atual.

2. **Navegação de produção usava `Navigator.of(context)` sem `rootNavigator: true`**  
   Fluxos estáveis do app (prontuário legado, ocorrências no MainRoot) usam **root navigator** para empurrar rotas acima do shell (`IndexedStack` + bottom nav + `PopScope`). O path da timeline era inconsistente com o padrão funcional.

3. **Falhas no navigate podiam ser silenciosas para o usuário**  
   `await _onNavigate` sem handler de erro no coordinator; future discardada no tap. Em falha pós-await, o usuário via “nada aconteceu” sem feedback controlado.

4. **Testes anteriores só injetavam `onTimelineNavigate` override**  
   Contavam callback — **nunca** montavam `WeightHistoryScreen` / `NutritionFullScreen` / `VaccinationHistoryScreen` via Navigator real.

**Não era** (descartado pela auditoria + testes e2e):
- chevron sem `onTap` (derivam do mesmo gate `isNavigable`);
- `_busy` preso no lifecycle antes do primeiro tap;
- lookup de Dog retornando null e abortando (path atual nunca cancela por Dog ausente — fallback mínimo).

## 4. Correção aplicada (mínima)

| Arquivo | Mudança |
|---------|---------|
| `health_timeline_screen.dart` | Coordinator com **métodos de State** (`_forwardNavigate` etc.) — sempre lê `widget.onNavigate` atual; remove definição duplicada de `_onEntryTap` (erro de compile); logs debug de tap/coordinator |
| `health_v1_entry_screen.dart` | `_onTimelineNavigate` com `Navigator.of(context, rootNavigator: true)`; Dog por `target.dogId` (catálogo → override → fallback); **nunca** return silencioso por Dog ausente; try/catch + `AppFeedback`; logs debug; sem import circular de `main.dart` |
| `health_timeline_navigation_coordinator.dart` | `onNavigateError` + try/catch; `_busy` sempre liberado no `finally` (Gate I) |

Escopo preservado: source 3C, paginator, mappers, cursor, filtros, FilterSession, shell, Summary, Agenda, rules, indexes, Functions, schema.

## 5. Testes adicionados

`test/features/health/presentation/timeline/health_timeline_3e_d2_nav_test.dart`

**Sem** `onTimelineNavigate` override — path de produção real.

| Gate | Prova |
|------|--------|
| A | tap weight → `WeightHistoryScreen` + dogId |
| B | tap feeding → `NutritionFullScreen` + dogId |
| C | tap vaccination → `VaccinationHistoryScreen` + dogId |
| D+E | back → Histórico; controller/session idênticos; filtros preservados |
| F | double tap → 1 destino |
| G | health_events → zero navegação |
| H | dog sem catálogo → fallback + ainda navega |
| I | falha no navigate → busy liberado + 2º tap funciona |
| sequência | weight → back → nutrition → back → vaccination |

**9/9 passed**

## 6. Gates A–I (automatizados 3E-D2)

| Gate | Automatizado | Manual device |
|------|--------------|---------------|
| A Weight real nav | **PASS** | **AGUARDANDO RETESTE EM DISPOSITIVO** |
| B Nutrition real nav | **PASS** | **AGUARDANDO RETESTE EM DISPOSITIVO** |
| C Vaccination real nav | **PASS** | **AGUARDANDO RETESTE EM DISPOSITIVO** |
| D Dog correto | **PASS** | **AGUARDANDO RETESTE EM DISPOSITIVO** |
| E Back preservation | **PASS** | **AGUARDANDO RETESTE EM DISPOSITIVO** |
| F Double tap | **PASS** | **AGUARDANDO RETESTE EM DISPOSITIVO** |
| G Unsupported | **PASS** | **AGUARDANDO RETESTE EM DISPOSITIVO** |
| H Dog fallback | **PASS** | **AGUARDANDO RETESTE EM DISPOSITIVO** |
| I Busy release | **PASS** | **AGUARDANDO RETESTE EM DISPOSITIVO** |

## 7. Validações

| Check | Resultado |
|-------|-----------|
| `flutter test …/health_timeline_3e_d2_nav_test.dart` | **9 passed** |
| `flutter test test/features/health/presentation/timeline` | **266 passed** |
| `flutter test test/features/health` | **688 passed** |
| `flutter test` (global) | **871 passed, 1 skipped** |
| `flutter analyze` (entry + timeline) | **No issues found** |
| `git diff --check` | **sem erros de whitespace** (só avisos LF/CRLF) |

## 8. Novo APK

| Item | Valor |
|------|--------|
| comando | `flutter build apk --debug --target-platform android-arm64` |
| Gradle | **✓ Built** `app-debug.apk` |
| data/hora | **2026-07-16 17:38:30** (local) |
| origem | `C:\Projetos\canil_gcm_mobile_chatgpt\canil-gcm\build\app\outputs\flutter-apk\app-debug.apk` |
| tamanho | **256748516** bytes |
| SHA-256 origem | `33B37B3C6A0296A11298465C6B5D24717CA55BF56AA5BE4059022F9EC7397D6C` |

## 9–10. Google Drive

| Campo | Valor |
|-------|--------|
| pasta | `G:\meu drive\apps k9` |
| nome | **`K9-Ops-Health-3E-D2-navfix-debug.apk`** |
| caminho | `G:\meu drive\apps k9\K9-Ops-Health-3E-D2-navfix-debug.apk` |
| tamanho | **256748516** bytes |
| SHA-256 destino | `33B37B3C6A0296A11298465C6B5D24717CA55BF56AA5BE4059022F9EC7397D6C` |
| hashes iguais | **True** |
| tamanho origem = destino | **True** |

## 11. Artefato não versionado

- APK em `/build` (gitignore)
- Cópia no Google Drive **fora** do repositório
- `git status` sem APK staged/tracked

## 12. Estado git (3E-D2)

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `a1afa1213d7e174372674763aed56d09e69fcd06` |
| commits 3E / 3E-D2 | **nenhum** (sem commit/push) |
| working tree | 3E-A + 3E-B + 3E-C + 3E-D1 + **3E-D2 nav fix** + testes + docs |

## 13. Status aguardando reteste

Instalar **`K9-Ops-Health-3E-D2-navfix-debug.apk`** (não reutilizar o APK 3E-D1).

Reteste manual obrigatório:

1. Saúde → Histórico  
2. Tap card **Pesagem** → deve abrir Histórico de Peso  
3. Voltar → Histórico preservado  
4. Tap **Alimentação** → Nutrição  
5. Voltar  
6. Tap **Vacinação** → Histórico de Vacinação  
7. Card não-navegável (se houver) → sem push  
8. Double tap → uma tela  

## 14. Classificação 3E-D2

# CORREÇÃO APLICADA — AGUARDANDO RETESTE EM DISPOSITIVO

Gates manuais G/H/I de navegação **não** são PASS até reteste no celular com o APK novo.

---

# 3E-D3 — Correções runtime finais

## 1. Evidência runtime (pós 3E-D2)

Retorno autenticado do usuário:

| Item | Status |
|------|--------|
| Health / Histórico / Firestore / filtros / paginação / FAB | **PASS** |
| Nav Pesagem | **PASS** |
| Nav Nutrição | **PASS** |
| **Nav Vacinação** | **FAIL** (card + tap → nada abre) |
| **Duplicidade de pesagem** | **FAIL** (1 ato → 2 entradas) |

## 2. Bug vacinação

```text
card VACINAÇÃO na Timeline
→ usuário toca
→ nenhuma tela abre
```

Peso e Nutrição funcionam no mesmo build (controles positivos).

## 3. Causa raiz vacinação

| Etapa | Weight | Nutrition | Vaccination (device real) |
|-------|--------|-----------|---------------------------|
| entry type | weight | meal | **vaccination** |
| sourceType real | weight_records | feeding_* | **`health_events`** |
| allowlist pré-3E-D3 | sim | sim | **não** (só `vacinas`) |
| resolver | WeightHistoryTarget | NutritionHistoryTarget | **unsupported** |
| onTap / chevron | sim | sim | **não** (isNavigable=false) |
| Navigator | OK | OK | **nunca chamado** |

**Prova no código:**

- `HealthSummaryVaccinationReader`: CRUD mobile ativo grava vacinas em  
  `dogs/{dogId}/health_events` com `type == vaccination`.
- Fallback `vacinas` permanece `enableVaccinationFallback = false`.
- Resolver 3D só resolvia `sourceType == vacinas`.
- Cards de vacinação vindos de `health_events` **não eram navegáveis**.  
  O toque no card sem InkWell resulta em “nada acontece”.

Não era falha de Navigator (Peso/Nutrição já usavam o mesmo path).

## 4. Correção vacinação

`HealthTimelineDetailResolver`:

- `health_events` entra na allowlist **somente** quando  
  `entryType.known == vaccination` → `VaccinationHistoryTarget` (relatedHistory).
- Outros `health_events` (consulta, exame, etc.) continuam **unsupported**.
- `vacinas` legado permanece resolvido como antes.
- Fallback de leitura **não** ativado.

## 5. Teste E2E vacinação

- Unit: `health_events + vaccination → VaccinationHistoryTarget`
- Widget (sem override de navigate):  
  tap card `health_events` vaccination → `VaccinationHistoryScreen` na árvore
- Regressão: consultation `health_events` → zero navegação  
  weight / nutrition / vacinas source → intactos

## 6. Bug duplicidade pesagem

Sintoma observado:

```text
REGISTRO DE SAÚDE
Registro de saúde · Pesagem
Pesagem efetuada em Canil.
```

+

```text
PESAGEM
Pesagem
30,0 kg
```

para **uma** ação de registro.

## 7. Fluxo real de escrita

`WeightHistoryScreen` (salvar pesagem):

```dart
await healthVM.addHealthLog(HealthLogModel(
  type: 'other',
  subtype: 'Pesagem',
  weight: _weight,
  healthObservations: 'Pesagem efetuada em $_selectedLocation.',
)); // → dogs/{id}/health_events (ID auto)

await WeightHistoryService().addRecord(...);
// → dogs/{id}/weight_records (ID auto diferente)
// → dogs/{id}/weight_history (mesmo ID do weight_records)
// → dogs/{id}.weight atualizado
```

## 8. Relação health_events × weight_records

| Campo | health_events (espelho) | weight_records (canônico) |
|-------|-------------------------|---------------------------|
| type/subtype | `other` / `Pesagem` | n/a (coleção especializada) |
| peso | `weight` | `weight_kg` |
| data | `date` (= log.date) | `measured_at` (= log.date) |
| obs | healthObservations | notes |
| doc ID | gerado por `.add()` | gerado por `.doc()` **diferente** |

## 9. Prova de identidade

**Não** há `source_id` / `weight_record_id` / docId compartilhado.

Identidade lógica = **contrato de dual-write comprovado no código**  
(payload exato `type=other + subtype=Pesagem + weight>0`).

Não usamos timestamp aproximado como regra única.

## 10. Estratégia de dedupe (read-side)

Em `HealthTimelineMappers.mapHealthEvent`:

```text
isProvenWeightDualWriteMirror(data)
→ TimelineIgnored('weight_dual_write_mirror')
```

Canônico na Timeline: **weight_records** (ADR-006 / navegável).

Nível: **mapper** (não UI). Independente de página → paginação OK.

## 11. Garantias contra falso positivo

**Não** ignora:

- health_events sem `weight` numérico;
- subtype ≠ Pesagem;
- type ≠ other (consulta, vacina, etc.);
- weight_records (sempre emitidos).

**Risco residual aceito e documentado:**  
`HealthViewModel.addWeightRecord` (type other + Pesagem + weight, só health_events)  
é código morto no app atual; se usado no futuro sem dual-write, sumiria da Timeline.  
Mitigação futura recomendada: write-side com `weight_record_id` ou docId compartilhado  
(**não implementado nesta fase** — 3E-D permanece read-side).

## 12. Paginação / cursor

- Dedupe no mapper → item nunca entra no residual.
- Cursor / watermark / global id inalterados.
- Versão do cursor inalterada.

## 13. Testes adicionados

| Caso | Resultado |
|------|-----------|
| payload dual-write → ignored | PASS |
| sem weight / subtype errado → não ignored | PASS |
| weight_record permanece | PASS |
| two weights próximos → 2 entradas | PASS |
| consultation intacta | PASS |
| health_events vaccination E2E nav | PASS |
| health_events consultation não navega | PASS |

## 14. Regressões

| Suite | Resultado |
|-------|-----------|
| timeline + coexistence | **326 passed** |
| `test/features/health` | **697 passed** |
| `flutter test` global | **880 passed, 1 skipped** |
| analyze (resolver + mappers) | **No issues found** |
| `git diff --check` | OK (avisos LF/CRLF) |

## 15–18. Build / APK / Drive / Hash

| Item | Valor |
|------|--------|
| comando | `flutter build apk --debug --target-platform android-arm64` |
| Gradle | **✓ Built** |
| timestamp | **2026-07-16 19:18:12** |
| origem | `build\app\outputs\flutter-apk\app-debug.apk` |
| tamanho | **256748516** bytes |
| Drive | `G:\meu drive\apps k9\K9-Ops-Health-3E-D3-runtime-fixes-debug.apk` |
| SHA-256 | `A42F08706EFC3A1C9AD0BD94C1CF11E28B27CFB8585E25C09FFF16EEACB6D77E` |
| hashes iguais | **True** |
| versionado | **não** |

## 19. Reteste manual pendente

Instalar **`K9-Ops-Health-3E-D3-runtime-fixes-debug.apk`**.

1. Card **Vacinação** → deve abrir Histórico de Vacinação  
2. Timeline com pesagens existentes → **uma** entrada lógica por ato dual-write  
3. Registrar **nova** pesagem → refresh Histórico → **uma** entrada (PESAGEM com kg), sem “Registro de saúde · Pesagem” espelho  

**Vacinação / Dedupe pesagem:**  
**AGUARDANDO RETESTE DEVICE** (não marcar PASS sem o usuário).

## 20. Achado Nutrição fora de escopo

Erro interno observado no fluxo legado de Nutrição (pós-navegação Timeline → Nutrição).

```text
ACHADO SEPARADO — FORA DO ESCOPO DA TIMELINE
```

Navegação Timeline → Nutrição permanece funcional. Não tratado nesta fase.

## 21. Estado git

| Item | Valor |
|------|--------|
| branch | `feature/health-v1-foundation` |
| HEAD | `a1afa1213d7e174372674763aed56d09e69fcd06` |
| divergência | `0/0` |
| commits 3E | **nenhum** |
| working tree | 3E-A…D2 + **3E-D3** uncommitted |

Arquivos 3E-D3 (produção):

- `lib/.../health_timeline_detail_resolver.dart`
- `lib/.../health_timeline_mappers.dart`

Testes:

- `health_timeline_detail_3d_test.dart`
- `health_timeline_3e_d2_nav_test.dart` (caso health_events vaccination)
- `coexistence_health_timeline_source_test.dart` (dual-write group)

## 22. Classificação 3E-D3

# CORREÇÕES APLICADAS — AGUARDANDO RETESTE EM DISPOSITIVO

Dedupe read-side segura **possível** (contrato dual-write comprovado).  
Write-side com vínculo explícito = evolução futura recomendada, **não bloqueante** desta fase.

---

# Conclusão final 3E-D — APROVADA EM DISPOSITIVO

Reteste manual pós 3E-D3 (usuário autenticado):

| Gate / item | Status |
|-------------|--------|
| Runtime principal (abre, cão, dados, filtros, empty) | **PASS DEVICE** |
| Paginação | **PASS DEVICE** |
| Footer / FAB / bottom nav | **PASS DEVICE** |
| Nav Peso | **PASS DEVICE** |
| Nav Nutrição | **PASS DEVICE** |
| Nav Vacinação | **PASS DEVICE** |
| Retorno das telas relacionadas | **PASS DEVICE** |
| Dedupe pesagem existente | **PASS DEVICE** |
| Nova pesagem → 1 entrada lógica | **PASS DEVICE** |
| Nova vacinação na Timeline | **PASS DEVICE** |

## Known issues / limitações (fora do fechamento Timeline)

| Código | Descrição |
|--------|-----------|
| **KNOWN ISSUE — Vaccination PDF export** | Carteira legada → Exportar PDF → erro. Não tratado na 3E. |
| **KNOWN COEXISTENCE LIMITATION** | Vacinas só em `health_events` na Timeline v1 podem não aparecer na Carteira legada. Sem dual-source forçado. |
| **DEBT dual-write peso** | Sem `source_id` explícito; dedupe por payload comprovado. Futuro write/projeção. |
| **F1 filtros cross-dog** | Residual 3E-C; decisão de produto. |

# FASE 3E-D APROVADA EM DISPOSITIVO

Polimento visual final e commit: **Fase 3E-E**.