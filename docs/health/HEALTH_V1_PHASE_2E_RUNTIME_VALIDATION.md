# Health v1.0 — Fase 2E-R — Validação Runtime e Correções

## 1. Contexto do teste real

- **Branch:** `feature/health-v1-foundation`
- **HEAD base (2D commit):** `03e41d2cc509a28461e0ee4d45944f61b559b261`
- **Working tree:** implementação 2E + correções 2E-R (não commitada)
- **Teste:** primeira instalação/execução em dispositivo real do APK debug pós-2E
- **Resultado geral:** entry, shell, Dashboard, K9 real, dados reais e navegação interna **funcionaram**; identidade visual base **aprovada como boa**
- **Não é redesenho:** 2E-R corrige apenas os seis achados objetivos

## 2. Achados

| ID | Descrição resumida |
|----|--------------------|
| R1 | Erros técnicos Firestore (index / URL / SDK) na UI |
| R2 | Scroll: Alimentação / Peso / Recentes atrás da bottom nav e FAB “Nova” |
| R3 | Bottom navigation transparente demais (conteúdo legível atrás) |
| R4 | Copy interna de arquitetura (“coexistência”, “legado”, “Health v1”…) |
| R5 | Cards de métrica `unavailable` com mensagem longa no valor principal |
| R6 | “REQUER ATENÇÃO” com `attention` unavailable (falsa afirmação) |

## 3. Severidades

| ID | Severidade | Motivo |
|----|------------|--------|
| R1 | Alta | Quebra confiança operacional; vaza infraestrutura |
| R2 | Alta | Impede leitura completa do conteúdo |
| R3 | Média | Contraste / hierarquia / acabamento |
| R4 | Média | Linguagem inadequada ao operador |
| R5 | Média | Truncamento e geometria ruim |
| R6 | Alta | Semântica clínica/operacional incorreta |

## 4. Causas encontradas

### R1

1. **Query com índice composto:**  
   `SoftDeletable.activeOnly(query).orderBy('date')` em  
   `dogs/{dogId}/health_events`  
   (`HealthSummaryRecentRecordsReader`; vacinação já usava padrão similar).  
   Firestore exige índice composto `deleted_at IS NULL` + `date DESC`.

2. **Propagação de `FirebaseException.message` / `Exception` bruto** para `SectionData.unavailable(message: …)` e daí aos cards.

### R2

- `Scaffold` do MainRoot com `extendBody: true`
- Bottom bar altura `76 + MediaQuery.padding.bottom`
- FAB eleva ~22 px acima da barra
- Dashboard tinha apenas `SizedBox(height: 8)` no fim do scroll — insuficiente

### R3

- `_navBg = AppTheme.primaryOverlay` (`0x0A4DD0E1`, ~4% alpha)
- Com `extendBody: true`, o conteúdo permanece legível atrás da barra

### R4

- Mensagens em `HealthSummaryUnsafeSections` e fallbacks de UI com jargão de engenharia

### R5

- `HealthSummaryMetricCard` usava `statusMessage` inteira como `primary` em unavailable/notRecorded

### R6

- Título fixo `REQUER ATENÇÃO` independente de `attention.status`

## 5. Correções

| ID | Arquivos principais | O que mudou |
|----|---------------------|-------------|
| R1 | `health_summary_*_reader.dart`, `health_summary_user_copy.dart`, source | Query sem activeOnly+orderBy; sanitize; debugPrint técnico |
| R2 | `health_summary_dashboard.dart` | `healthSummaryScrollBottomClearance` no scroll |
| R3 | `main_root_actions.dart` | `_navBg = surfaceNavigation` (global) |
| R4 | `health_summary_unsafe_sections.dart`, copy helper | Frases operacionais |
| R5 | `health_summary_metric_card.dart` | Primary curto `INDISPONÍVEL` / `NÃO REGISTRADO` |
| R6 | `health_summary_attention_section.dart`, metrics accent | Título condicional + cor neutra |

**Não alterado:** contratos 2B, política 2D (readiness/treatments/attention continuam unavailable), ordem do Dashboard, peso/gráfico sem necessidade, readiness real, writes, índices remotos.

## 6. Query / index investigation

### QUERY QUE EXIGIA ÍNDICE

| Campo | Valor |
|-------|--------|
| **coleção** | `dogs/{dogId}/health_events` |
| **filtros** | `where('deleted_at', isNull: true)` via `SoftDeletable.activeOnly` |
| **orderBy** | `date` descending |
| **limite** | 20 (recentes) / similar em vacinação pré-fix |
| **readers** | `HealthSummaryRecentRecordsReader._healthEvents`; caminho vacinação já alinhado |
| **motivo** | igualdade em `deleted_at` + orderBy em outro campo → índice composto |

### Correção aplicada

```text
orderBy('date', descending: true).limit(N)
// + filtro deleted_at != null no cliente
```

`vacinas` (fallback): equality `caoId` sem orderBy; sort no cliente.

### Classificação

**RESOLVIDA SEM ÍNDICE**

Não foi criado índice. Não houve alteração em `firestore.indexes.json`.  
Se no futuro o volume de `health_events` soft-deletados crescer muito, um índice composto pode ser reavaliado — **não** nesta fase.

### Outras queries (sem mudança estrutural)

| Query | Nota |
|-------|------|
| `weight_records` orderBy `measured_at` | single-field; funcionou no device |
| `feeding_events` / `feedings` range em `fed_at` | padrão NutritionService; sem achado de index no teste |

## 7. Bottom navigation

- **Antes:** `primaryOverlay` quase transparente  
- **Depois:** `AppTheme.surfaceNavigation` (`#07141B`) navy sólido  
- **Escopo:** global (todas as abas) — não hack só de Saúde  
- **Preservado:** borda superior `primaryDivider`, pills, FAB “Nova”, layout  
- **Teste de regressão:** token solidificado + renderização inalterada estruturalmente; inspeção visual multi-aba na segunda rodada no device

## 8. Scroll / safe area

```dart
// healthSummaryScrollBottomClearance
76 (nav content) + MediaQuery.padding.bottom + 28 (folga FAB)
```

Aplicado ao `SingleChildScrollView` de dados e loading do Dashboard.  
Considera gesture navigation (system bottom) e nav bar tradicional.

## 9. Estados unavailable

| Bloco | Continua | UI |
|-------|----------|-----|
| readiness | unavailable (2D) | badge INDISPONÍVEL + copy operacional |
| treatments | unavailable | card INDISPONÍVEL |
| attention | unavailable | seção ATENÇÕES neutra + mensagem |
| vaccination (erro) | unavailable | card INDISPONÍVEL (sem SDK) |
| recent (erro) | unavailable | mensagem operacional |

**Regra mantida:** unavailable ≠ notRecorded; erro ≠ lista vazia.

## 10. Copy operacional

Centralizada em `HealthSummaryUserCopy`:

- Prontidão / tratamentos / atenções / vacinação / peso / nutrição / recentes  
- `sanitizeUnavailable` / `looksTechnical` bloqueiam index, firebase, URLs, jargão

## 11. Semântica de atenções

| status | Título | Cor |
|--------|--------|-----|
| available + items | REQUER ATENÇÃO | âmbar |
| available + vazio | ATENÇÕES | neutro + empty positivo |
| notRecorded | ATENÇÕES | neutro / empty |
| unavailable | ATENÇÕES | neutro + mensagem |
| loading | ATENÇÕES | skeleton |

Semantics do header segue o título renderizado.

## 12. Testes adicionados/atualizados

| Arquivo | Cobertura |
|---------|-----------|
| `health_summary_runtime_2er_test.dart` | **novo** — sanitize, metrics unavailable/notRecorded, atenção R6, copy, bottom padding, nav token |
| `health_summary_dashboard_test.dart` | expectativas R5/R6 atualizadas |
| `coexistence_health_summary_source_test.dart` | sanitize em falha de vacina/peso; copy unsafe sem jargão |

## 13. Validações

| Comando | Resultado observado (pós-2E-R; pré-auditoria) |
|---------|---------------------|
| `dart format --set-exit-if-changed` (arquivos 2E-R) | **exit 0** (após format) |
| `flutter analyze` (health + main_root*) | 29 **info** preexistentes em domain; **0** issues novas nos arquivos 2E-R |
| `flutter test test/features/health` | **346 passed** |
| `flutter test` (suite completa) | **529 passed, 1 skipped**, exit **0** |
| `git diff --check` | **exit 0** |
| `flutter build apk --debug` | **exit 0**, APK gerado |

> Auditoria final 2E elevou a suite health (soft-delete+limit, gate, offline). Ver `HEALTH_V1_PHASE_2E_AUDIT.md` §28 para contagens pós-auditoria.

## 14. Novo APK

| Campo | Valor |
|-------|--------|
| Comando | `flutter build apk --debug` |
| Exit code | **0** |
| Artefato | `build/app/outputs/flutter-apk/app-debug.apk` |
| Caminho absoluto | `C:\Projetos\canil_gcm_mobile_chatgpt\canil-gcm\build\app\outputs\flutter-apk\app-debug.apk` |
| LastWriteTime | 2026-07-15 ~18:02:40 |
| Tamanho aprox. | ~292 MB (debug) |
| Instalação automática | **não** |

## 15. Segunda validação em dispositivo

**Resultado: APROVADA VISUALMENTE PARA A FASE 2E**

Confirmado pelo operador no APK 2E-R:

- Health v1 abre; K9 real; dados reais  
- sem erro técnico Firestore na UI  
- cards unavailable limpos; ATENÇÕES neutras  
- scroll não bloqueado pela bottom nav  
- nav navy sólida; FAB “Nova” preservado  
- peso, gráfico e nutrição funcionais  
- navegação interna e retorno ao app OK  

Não se afirma mockup pixel-perfect.

## 16. Pendências pós-aprovação visual

- Auditoria adversarial final → `HEALTH_V1_PHASE_2E_AUDIT.md`  
- Commit sob ordem explícita (não automático)  
- Dívidas: entry points legados paralelos; índice se volume soft-delete extremo  

## 17. Conclusão

**Classificação visual:** aprovada para a fase 2E.  
**Classificação técnica:** ver auditoria final (gate soft-delete+limit, offline, rollback).

Princípio respeitado: **corrigir representação, não inventar dados.**
