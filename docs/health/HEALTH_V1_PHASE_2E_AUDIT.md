# Health v1.0 — Fase 2E + 2E-R — Auditoria Técnica Adversarial Final

## 1. Preflight

| Item | Valor |
|------|--------|
| Branch | `feature/health-v1-foundation` |
| HEAD base | `03e41d2cc509a28461e0ee4d45944f61b559b261` |
| Commit base | `feat(health): add read-only summary coexistence source` |
| Tracking | `origin/feature/health-v1-foundation` |
| Divergência | `0/0` |
| Working tree | **apenas** 2E + 2E-R (+ correções desta auditoria) |

Nenhuma alteração estranha fora do escopo. Sem reset/stash.

## 2. Arquivos auditados

### Integração 2E
- `health_v1_entry_screen.dart`, `health_v1_entry_flags.dart`
- `main_root_screen.dart`, `main_root_widgets.dart`, `main_root_actions.dart`
- `main_root_nav_metrics.dart` (introduzido na auditoria)

### Camadas
- `HealthShellScreen`, `HealthSummaryController`, `HealthSummaryDashboard`
- `HealthSummaryDogContextMapper`, `CoexistenceHealthSummarySource`

### 2E-R / readers
- `HealthSummaryUserCopy`, metric/attention widgets, unsafe sections
- weight / vaccination / nutrition / recent readers
- `health_summary_soft_delete.dart` (introduzido na auditoria)

### Testes
- entry 2E, runtime 2E-R, coexistence 2D, soft-delete+limit

### Documentação
- reports/audit 2C–2D, 2E report, 2E runtime validation

## 3. Metodologia

1. Preflight git + inventário de diff  
2. Leitura de código (não só relatórios)  
3. Busca de writes / migrations / indices no escopo  
4. Ataque prioritário: soft-delete+limit, lifecycle, gate, offline, sanitização  
5. Teste obrigatório soft-delete+limit  
6. Correções cirúrgicas de achados ALTA/MÉDIA  
7. Revalidação format/analyze/test/apk  

## 4. Achados

### A1 — Perda silenciosa soft-delete + limit (ALTA) — **CORRIGIDO**

| Campo | Valor |
|-------|--------|
| Severidade | **ALTA** |
| Arquivos | `health_summary_recent_records_reader.dart`, `health_summary_vaccination_reader.dart` |
| Problema | `orderBy(date).limit(N)` no servidor **antes** do filtro `deleted_at` no cliente. Se os N mais recentes estiverem soft-deleted, ativos mais antigos **nunca** entravam na janela. |
| Impacto | Lista de recentes / vacinação podia parecer vazia ou cair em fallback incorreto apesar de dados ativos existirem. |
| Correção | `HealthSummarySoftDelete.paginateActiveMapped`: pagina até `targetActive` itens mapeados ou esgota páginas (page 50 × max 6). |

### A2 — Sinal offline perdido após sanitização (ALTA) — **CORRIGIDO**

| Campo | Valor |
|-------|--------|
| Severidade | **ALTA** |
| Arquivos | readers + `coexistence_health_summary_source.dart` + `HealthSummaryUserCopy` |
| Problema | Mensagens genéricas sanitizadas não continham `offline`/`network`; `_looksOffline` falhava e **todas as fontes mapeáveis offline** viravam `error` em vez de `offline`. |
| Impacto | UX de canal offline incorreta; retry/semântica de rede degradada. |
| Correção | `networkUnavailable` + detecção de “conectar/rede” + `FirebaseException.code == unavailable` → copy de rede. |

### A3 — Gate false sem prova automatizada (MÉDIA) — **CORRIGIDO**

| Campo | Valor |
|-------|--------|
| Severidade | **MÉDIA** |
| Arquivo | `health_v1_entry_flags.dart` + testes |
| Problema | Rollback era só const + branch em código; sem helper testável. |
| Correção | `shouldUseHealthV1SummaryEntry(overrideGate:)` + testes true/false. |

### A4 — Constantes de nav duplicadas (BAIXA) — **CORRIGIDO**

| Campo | Valor |
|-------|--------|
| Severidade | **BAIXA** |
| Arquivos | `main_root_actions` / dashboard clearance |
| Problema | `76` / `28` magic numbers com risco de drift. |
| Correção | `MainRootNavMetrics` fonte única. |

### A5 — ValueKey + didUpdateWidget (INFO)

| Campo | Valor |
|-------|--------|
| Severidade | **INFO** |
| Problema | Em produção, `ValueKey('health-v1-$dogId')` recria o State; `didUpdateWidget` quase não roda. |
| Avaliação | Proteção **complementar legítima** (testes / reuso sem key). Não é bug. Teste adicionado para o caminho sem key. |

### A6 — Identidade “Carregando…” / “K9” (INFO)

| Campo | Valor |
|-------|--------|
| Severidade | **INFO** |
| Problema | Nome genérico enquanto catálogo carrega. |
| Avaliação | `dogContext.dogId` permanece o `activeDogId` correto; payload de saúde usa o mesmo id; mismatch banner se `dogContext.dogId != data.dogId`. **Não** cruza saúde de um cão com identidade de outro. |

### A7 — Entry points legados (INFO)

| Campo | Valor |
|-------|--------|
| Severidade | **INFO** |
| Problema | Header binômio / quick actions ainda abrem prontuário legado. |
| Avaliação | Sem corrupção de dados; possível confusão UX. Documentado para fase futura — **não** alinhado nesta auditoria. |

### A8 — + Registrar snackbar (INFO)

Placeholder controlado; sem write; mensagem “em breve”.

### A9 — Subfonte recentes com Future.wait (INFO)

Se **qualquer** de health_events / weights / feedings falhar, o bloco inteiro fica `unavailable`. Intencional (não misturar partial com falha silenciosa). Documentado no reader.

## 5. Correções realizadas nesta auditoria

1. `health_summary_soft_delete.dart` + paginação nos readers de vacinação/recentes  
2. `networkUnavailable` + offline detection  
3. `shouldUseHealthV1SummaryEntry`  
4. `MainRootNavMetrics`  
5. Testes soft-delete+limit (gate obrigatório), gate false, didUpdateWidget, offline global  
6. Docs atualizados  

## 6. Escopo

Busca no diff 2E/2E-R:

| Item | Presente? |
|------|-----------|
| write novo | **não** |
| migration | **não** |
| dual-write | **não** |
| Cloud Function | **não** |
| Rule | **não** |
| índice (`firestore.indexes.json`) | **não** |
| projeção canônica | **não** |
| cálculo readiness | **não** |
| score legado | **não** |
| Histórico/Agenda/Nutrição v1 completos | **não** (placeholders) |
| Hub de registros | **não** |
| remoção legado | **não** |

## 7. Entry point

**Antes:** `_MainRootHealthTab` → `DogHealthProntuarioScreen(dogId)`  

**Depois:** se `shouldUseHealthV1SummaryEntry()` → `HealthV1EntryScreen(key: health-v1-$dogId, dogId)` senão legado.

- Sem K9 / sem turno: mensagem existente **antes** do entry (não monta v1).  
- Índices de tab inalterados.  
- Sem route loop.  

## 8. Feature gate / rollback

| | |
|--|--|
| Valor produção APK | `kHealthV1SummaryEntryEnabled = **true**` |
| true | monta Entry (source + controller) |
| false | `DogHealthProntuarioScreen` — **não** instancia Entry/source/controller |
| Rollback | trocar flag para false (1 const) |

## 9. Lifecycle

| Fase | Comportamento |
|------|----------------|
| initState | source 1×, controller 1×, `selectDog` |
| didUpdateWidget | se dogId trim mudou e não vazio → `selectDog` |
| dispose | `controller.dispose` (cancela subscription) |
| ValueKey | recreate completo na troca de K9 na aba |

Controller 2B: generation + dogId ignoram emissões tardias; cache por dogId.

## 10. Dog context

`ShiftViewModel.activeDogId` → busca em `DogViewModel.dogs` → mapper.  
Fallback nome genérico **com mesmo dogId**. Sem cruzamento de identidades.

## 11. Troca de K9

Provas:

- teste ValueKey A→B  
- teste didUpdateWidget sem key  
- controller generation (2B)  

Não mostra Alpha com dados de Bravo.

## 12. Source 2D no runtime

`CoexistenceHealthSummarySource` one-shot; partial unavailable; unsafe sections inalteradas semanticamente.

## 13. Query / index

| | |
|--|--|
| Classificação | **RESOLVIDA SEM ÍNDICE** (com paginação) |
| Query | `health_events` orderBy `date` DESC, páginas de 50 |
| Sem | `where deleted_at isNull` (evita índice composto) |

## 14. Soft-delete + limit

Gate obrigatório: `health_summary_soft_delete_limit_test.dart` — **PASS**.

- Soft-deleted nunca mapeados  
- `deleted_at` ausente/null = ativo  
- Janela só deletados + página com ativos → ativos recuperados  

## 15. Vacinação

- health_events principal com paginação de ativos  
- fallback `vacinas` só se principal **vazia com sucesso**  
- erro estrutural não cai no fallback  
- sem “Em dia”; sem `dataVencimento` → nextDueAt  

## 16. Registros recentes

- health_events (paginado) + weights + dual feedings  
- limit final 8 após merge/sort  
- dedupe feeding por doc id  
- falha de subfonte → bloco unavailable (intencional)  

## 17. Sanitização

`sanitizeUnavailable` bloqueia index/firebase/URL/permission/jargão.  
**Estado semântico preservado** (unavailable continua unavailable).  
Rede: mensagem distinta + offline detection.

## 18. Falha global

Todas mapeáveis unavailable → `HealthSummarySourceException` (não Data).  
Rede → `isOffline: true`. Teste adicionado.

## 19–20. Unavailable / Atenções

Confirmado em UI e testes 2E-R (INDISPONÍVEL vs NÃO REGISTRADO; REQUER ATENÇÃO só com items).

## 21. Bottom navigation

`_navBg = surfaceNavigation` (sólido). Global. FAB/pills preservados. Segunda inspeção visual aprovou.

## 22. Scroll / safe area

`MainRootNavMetrics.scrollBottomClearance`. Aplicado em data + loading; error/offline com lastKnown usam `_DataScroll` (mesma clearance). Surface messages (sem scroll longo) OK.

## 23. + Registrar

Snackbar informativo. INFO.

## 24. Outros entry points

Legado permanece. INFO / dívida futura.

## 25. Testes

| Suite | Cobertura |
|-------|-----------|
| Entry 2E | gate true/false, shell, dogId, A→B key, didUpdateWidget, dispose |
| 2E-R runtime | sanitize, metrics, R6, padding, nav |
| soft-delete+limit | **obrigatório** — pass |
| coexistence | partial, global fail, offline pós-sanitize |

## 26. Segunda validação visual

**APROVADA VISUALMENTE PARA A FASE 2E** (relato do usuário após APK 2E-R):

- abre, K9 real, dados reais  
- sem erros Firestore na UI  
- unavailable limpos; ATENÇÕES neutras  
- scroll acima da nav; nav navy; FAB ok  
- peso/gráfico/nutrição; navegação interna  

Não se afirma pixel-perfect.

## 27. Build APK

Ver seção 28 (validações). Artefato esperado: `build/app/outputs/flutter-apk/app-debug.apk`.

## 28. Validações finais

| Comando | Resultado |
|---------|-----------|
| `dart format --set-exit-if-changed` (escopo 2E) | limpo (exit 0 após format) |
| `flutter analyze` (escopo 2E alterado) | sem issues novas no escopo (infos preexistentes de domain fora) |
| `flutter test test/features/health` | **359 passed**, exit **0** |
| `flutter test` (global) | **542 passed, 1 skipped**, exit **0** |
| `git diff --check` | **0** |
| `flutter build apk --debug` | **exit 0**, APK gerado (~18:44 local) |
| `flutter analyze` (escopo pós-fix warnings) | **No issues found** (exit 0) |

Critério: 0 novos erros/warnings causados por 2E/2E-R/auditoria no escopo alterado.

## 29. Diferenças versus relatórios anteriores

| Antes | Depois (auditoria) |
|-------|---------------------|
| limit fixo + filtro cliente | paginação até targetActive |
| offline detection frágil pós-sanitize | networkUnavailable + looksOffline |
| magic 76/28 | MainRootNavMetrics |
| gate só const | helper + testes |
| runtime doc “suite em execução” | resultados finais |

## 30. Riscos restantes

### Varredura limitada (soft-delete + maxPages) — semântica fechada

- `pageSize=50`, `maxPages=6` são **proteção de custo**, não afirmação de verdade.
- Se o teto for atingido **sem** esgotar a coleção (última página cheia e target não atingido):
  - resultado **truncated / inconclusivo**;
  - **não** vira `notRecorded` / ausência falsa;
  - vacinação: **sem** fallback `vacinas`;
  - recentes: bloco **unavailable** (não partial silencioso com pesos/refeições).
- Índice composto pode ser considerado **futuramente** por performance (não nesta fase).

Outros:

- Entry points legados paralelos (UX).  
- Placeholders Histórico/Agenda/Nutrição.  
- Source one-shot (sem push contínuo).  

Nenhum crítico residual no escopo 2E (pós microcorreção de truncamento).

## 31. Pendências futuras

- Alinhar atalhos secundários ao Health v1  
- Índice composto opcional se volume soft-delete crescer (performance, não semântica)  
- 2F+ (fora de escopo)  
- Commit sob ordem explícita  

## 32. Conclusão

# APROVADA PARA COMMIT

Critérios:

- [x] nenhuma CRÍTICA / ALTA / MÉDIA aberta  
- [x] soft-delete + limit testado e corrigido  
- [x] truncamento por maxPages **não** vira vazio legítimo (microcorreção final)  
- [x] rollback comprovado  
- [x] lifecycle correto  
- [x] segunda validação visual documentada  
- [x] build e testes verdes (ver rodapé de validações no report atualizado)  

**Não commitado nesta sessão** (conforme instrução).